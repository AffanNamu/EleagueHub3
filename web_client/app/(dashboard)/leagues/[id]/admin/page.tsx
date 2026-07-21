'use client';

import { useState, useEffect } from 'react';
import { useRouter, useParams } from 'next/navigation';
import { motion, AnimatePresence } from 'framer-motion';
import { 
  ArrowLeft, RefreshCw, Trash2, Mic, Wifi, Shield,
  MessageSquare, DownloadCloud, Ticket, Activity,
  CheckCircle2, X, Users, Gift
} from 'lucide-react';
import { auth } from '@/lib/firebase';
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

  const [pointTeamId, setPointTeamId] = useState('');
  const [pointType, setPointType] = useState<'addition' | 'deduction'>('addition');
  const [pointAmount, setPointAmount] = useState('');
  const [pointReason, setPointReason] = useState('');
  const [annTitle, setAnnTitle] = useState('');
  const [annMsg, setAnnMsg] = useState('');
  const [couponMode, setCouponMode] = useState<'random' | 'custom'>('random');
  const [couponCount, setCouponCount] = useState('10');
  const [couponCustom, setCouponCustom] = useState('');

  useEffect(() => {
    setMounted(true);
  }, []);

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
    if (mounted && authUid && leagueId) {
      loadData();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mounted, authUid, leagueId]);

  if (!mounted || loading || !data) {
    return (
      <div className="min-h-screen bg-[#081120] flex items-center justify-center">
        <div className="w-12 h-12 border-4 border-brand-lime border-t-transparent rounded-full animate-spin" />
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
      setActiveModal('none');
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
      await toggleSpaceStatusWeb(leagueId, true, authUid, data.league.name);
      showSnack('Live Space Started!');
    } catch (err: any) {
      showSnack(err.message || 'Failed to start space', true);
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
      setActiveModal('none');
    } catch (err: any) {
      showSnack(err.message || 'Generation failed', true);
    } finally {
      setIsProcessing(false);
    }
  };

  return (
    <div className="min-h-screen bg-[#081120] text-white font-sans selection:bg-brand-lime selection:text-slate-900 pb-20">
      
      <header className="sticky top-0 z-40 bg-[#081120]/80 backdrop-blur-md border-b border-white/5 px-4 h-16 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <button onClick={() => router.push(`/leagues/${leagueId}`)} className="w-10 h-10 flex items-center justify-center rounded-full bg-white/5 hover:bg-white/10 text-slate-300 transition-colors">
            <ArrowLeft className="w-5 h-5" />
          </button>
          <h1 className="text-lg font-black tracking-tight">League Admin</h1>
        </div>
        <button onClick={loadData} className="w-10 h-10 flex items-center justify-center rounded-full bg-white/5 hover:bg-white/10 text-brand-lime transition-colors">
          <RefreshCw className={`w-4 h-4 ${isProcessing ? 'animate-spin' : ''}`} />
        </button>
      </header>

      <div className="fixed top-20 left-1/2 -translate-x-1/2 z-50 w-full max-w-sm px-4 pointer-events-none flex flex-col gap-2">
        <AnimatePresence>
          {error && (
            <motion.div initial={{ opacity: 0, y: -20 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -20 }} className="w-full p-4 rounded-xl bg-red-500/90 backdrop-blur-md text-white font-bold text-sm shadow-xl flex items-center gap-3">
              <Shield className="w-5 h-5" /> {error}
            </motion.div>
          )}
          {success && (
            <motion.div initial={{ opacity: 0, y: -20 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -20 }} className="w-full p-4 rounded-xl bg-brand-lime/90 backdrop-blur-md text-slate-900 font-bold text-sm shadow-xl flex items-center gap-3">
              <CheckCircle2 className="w-5 h-5" /> {success}
            </motion.div>
          )}
        </AnimatePresence>
      </div>

      <main className="max-w-2xl mx-auto px-4 sm:px-6 mt-8 space-y-4">
        
        <div className="p-5 rounded-3xl bg-brand-lime/10 border border-brand-lime/20 shadow-xl flex items-center gap-4 mb-6">
          <div className="w-12 h-12 rounded-2xl bg-brand-lime/20 flex items-center justify-center shrink-0">
            <Wifi className="w-6 h-6 text-brand-lime" />
          </div>
          <div>
            <h3 className="text-base font-black text-white">Online & Connected</h3>
            <p className="text-xs font-semibold text-slate-400 mt-1">Changes save directly to Firestore instantly.</p>
          </div>
        </div>

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
          icon={Mic} title="Start Live Voice Space" subtitle="Host an audio room for this league"
          onClick={handleToggleSpace} loading={isProcessing}
        />

        <div className="pt-8">
          <AdminActionCard 
            icon={Trash2} title="Delete League" subtitle="Permanently destroy this competition" destructive
            onClick={() => setActiveModal('delete')}
          />
        </div>
      </main>

      <AnimatePresence>
        {activeModal !== 'none' && (
          <div className="fixed inset-0 z-[100] flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm">
            <motion.div 
              initial={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.95 }}
              className="w-full max-w-md bg-[#0F172A] border border-white/10 rounded-3xl p-6 shadow-2xl relative max-h-[90vh] overflow-y-auto"
            >
              <button onClick={() => setActiveModal('none')} className="absolute top-4 right-4 text-slate-400 hover:text-white">
                <X className="w-5 h-5" />
              </button>

              {activeModal === 'delete' && (
                <>
                  <h2 className="text-xl font-black text-white mb-2">Delete League?</h2>
                  <p className="text-sm font-medium text-slate-400 mb-6">This action is irreversible. All data will be purged.</p>
                  <button onClick={handleDelete} disabled={isProcessing} className="w-full py-3.5 rounded-xl bg-red-500 text-white font-black hover:bg-red-600 disabled:opacity-50">
                    {isProcessing ? 'Deleting...' : 'Confirm Deletion'}
                  </button>
                </>
              )}

              {activeModal === 'announcement' && (
                <>
                  <h2 className="text-xl font-black text-white mb-2">Send Announcement</h2>
                  <p className="text-sm font-medium text-slate-400 mb-6">Broadcast a message to the league dashboard.</p>
                  <div className="space-y-4 mb-6">
                    <input type="text" placeholder="Title (Optional)" value={annTitle} onChange={e => setAnnTitle(e.target.value)} className="w-full p-3 bg-white/5 border border-white/10 rounded-xl text-white outline-none focus:border-brand-lime" />
                    <textarea placeholder="Message (Required)" value={annMsg} onChange={e => setAnnMsg(e.target.value)} rows={3} className="w-full p-3 bg-white/5 border border-white/10 rounded-xl text-white outline-none focus:border-brand-lime resize-none" />
                  </div>
                  <button onClick={handleSendAnnouncement} disabled={isProcessing || !annMsg.trim()} className="w-full py-3.5 rounded-xl bg-brand-lime text-slate-900 font-black hover:brightness-110 disabled:opacity-50">
                    {isProcessing ? 'Sending...' : 'Send Now'}
                  </button>
                </>
              )}

              {activeModal === 'points' && (
                <>
                  <h2 className="text-xl font-black text-white mb-2">Adjust Points</h2>
                  <p className="text-sm font-medium text-slate-400 mb-6">Modify team standings securely.</p>
                  <div className="space-y-4 mb-6">
                    <select value={pointTeamId} onChange={e => setPointTeamId(e.target.value)} className="w-full p-3 bg-white/5 border border-white/10 rounded-xl text-white outline-none focus:border-brand-lime">
                      {Object.values(data.teams).map(t => <option key={t.id} value={t.id} className="text-slate-900">{t.name}</option>)}
                    </select>
                    <div className="flex gap-2">
                      <button onClick={() => setPointType('addition')} className={`flex-1 py-2 rounded-lg border font-bold text-sm transition-all ${pointType === 'addition' ? 'bg-green-500/20 border-green-500 text-green-400' : 'bg-white/5 border-white/10 text-slate-400'}`}>+ Add</button>
                      <button onClick={() => setPointType('deduction')} className={`flex-1 py-2 rounded-lg border font-bold text-sm transition-all ${pointType === 'deduction' ? 'bg-red-500/20 border-red-500 text-red-400' : 'bg-white/5 border-white/10 text-slate-400'}`}>- Deduct</button>
                    </div>
                    <input type="number" placeholder="Points" value={pointAmount} onChange={e => setPointAmount(e.target.value)} className="w-full p-3 bg-white/5 border border-white/10 rounded-xl text-white outline-none focus:border-brand-lime" />
                    <input type="text" placeholder="Reason (Required)" value={pointReason} onChange={e => setPointReason(e.target.value)} className="w-full p-3 bg-white/5 border border-white/10 rounded-xl text-white outline-none focus:border-brand-lime" />
                  </div>
                  <button onClick={handlePointAdjustment} disabled={isProcessing} className="w-full py-3.5 rounded-xl bg-brand-lime text-slate-900 font-black hover:brightness-110 disabled:opacity-50">
                    {isProcessing ? 'Applying...' : 'Apply Adjustment'}
                  </button>
                </>
              )}

              {activeModal === 'coupons' && (
                <>
                  <h2 className="text-xl font-black text-white mb-2">Coupon Codes</h2>
                  <p className="text-sm font-medium text-slate-400 mb-6">Must initialize configuration before generating.</p>
                  <div className="space-y-4 mb-6">
                    <button onClick={handleInitCoupons} disabled={isProcessing} className="w-full py-3 rounded-xl border border-sky-500/50 text-sky-400 font-bold hover:bg-sky-500/10 transition-colors">
                      Initialize / Reset Configuration
                    </button>
                    <div className="h-px bg-white/10 w-full my-2" />
                    <div className="flex gap-2">
                      <button onClick={() => setCouponMode('random')} className={`flex-1 py-2 rounded-lg border font-bold text-xs transition-all ${couponMode === 'random' ? 'bg-brand-lime/20 border-brand-lime text-brand-lime' : 'bg-white/5 border-white/10 text-slate-400'}`}>Random</button>
                      <button onClick={() => setCouponMode('custom')} className={`flex-1 py-2 rounded-lg border font-bold text-xs transition-all ${couponMode === 'custom' ? 'bg-brand-lime/20 border-brand-lime text-brand-lime' : 'bg-white/5 border-white/10 text-slate-400'}`}>Custom</button>
                    </div>
                    {couponMode === 'random' ? (
                      <input type="number" placeholder="How many codes?" value={couponCount} onChange={e => setCouponCount(e.target.value)} className="w-full p-3 bg-white/5 border border-white/10 rounded-xl text-white outline-none focus:border-brand-lime" />
                    ) : (
                      <input type="text" placeholder="Custom code (e.g. BARCA)" value={couponCustom} onChange={e => setCouponCustom(e.target.value)} className="w-full p-3 bg-white/5 border border-white/10 rounded-xl text-white outline-none focus:border-brand-lime uppercase" />
                    )}
                  </div>
                  <button onClick={handleGenerateCoupons} disabled={isProcessing} className="w-full py-3.5 rounded-xl bg-brand-lime text-slate-900 font-black hover:brightness-110 disabled:opacity-50">
                    {isProcessing ? 'Generating...' : 'Generate Codes'}
                  </button>
                </>
              )}
            </motion.div>
          </div>
        )}
      </AnimatePresence>

    </div>
  );
}

function AdminActionCard({ icon: Icon, title, subtitle, onClick, destructive = false, loading = false }: any) {
  return (
    <button onClick={onClick} disabled={loading} className={`w-full flex items-center gap-4 p-5 rounded-3xl border transition-all text-left ${destructive ? 'bg-red-500/5 border-red-500/20 hover:bg-red-500/10' : 'bg-[#0F172A] border-white/5 hover:bg-white/[0.02] hover:border-white/10'}`}>
      <div className={`w-10 h-10 rounded-full flex items-center justify-center shrink-0 ${destructive ? 'bg-red-500/10 text-red-500' : 'bg-brand-lime/10 text-brand-lime'}`}>
        {loading ? <div className="w-5 h-5 border-2 border-current border-t-transparent rounded-full animate-spin" /> : <Icon className="w-5 h-5" />}
      </div>
      <div className="flex-1">
        <h3 className={`text-sm font-black ${destructive ? 'text-red-500' : 'text-white'}`}>{title}</h3>
        <p className={`text-xs font-semibold mt-1 leading-relaxed ${destructive ? 'text-red-400/80' : 'text-slate-400'}`}>{subtitle}</p>
      </div>
    </button>
  );
}
