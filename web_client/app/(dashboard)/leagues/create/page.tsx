'use client';

import { useState, useRef, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { collection, doc, setDoc, getDoc, getDocs, query, where, limit } from 'firebase/firestore';
import { auth, db } from '@/lib/firebase';
import { uploadImageToCloudinary } from '@/lib/cloudinary';
import { LeagueFormat, FootballCategory, LeaguePrivacy, WorldCupFormat } from '@/types/league';
import { 
  Loader2, ArrowLeft, Image as ImageIcon, Trophy, 
  ShieldAlert, Globe, LayoutGrid, ListOrdered, Lock, 
  CreditCard, CheckCircle2, Mic
} from 'lucide-react';

const FREE_LEAGUE_LIMIT = 3;

// Categories mapped directly from Flutter's FootballCategoryUtil.all
const FOOTBALL_CATEGORIES: { id: FootballCategory, label: string }[] = [
  { id: 'localFootball', label: 'Local Football' },
  { id: 'eFootball', label: 'eFootball' },
  { id: 'eaSportsFc', label: 'EA SPORTS FC' },
  { id: 'eaSportsFcMobile', label: 'FC Mobile' },
  { id: 'dreamLeagueSoccer', label: 'Dream League Soccer' },
  { id: 'totalFootball', label: 'Total Football' },
];

export default function CreateLeagueScreen() {
  const router = useRouter();
  
  // Access & Limits State
  const [authUid, setAuthUid] = useState<string | null>(null);
  const [checkingAccess, setCheckingAccess] = useState(true);
  const [isPremium, setIsPremium] = useState(false);
  const [createdCount, setCreatedCount] = useState(0);

  // Form State
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  
  // Images
  const leagueImageRef = useRef<HTMLInputElement>(null);
  const sponsorImageRef = useRef<HTMLInputElement>(null);
  const [leagueImageFile, setLeagueImageFile] = useState<File | null>(null);
  const [leagueImagePreview, setLeagueImagePreview] = useState<string | null>(null);
  const [sponsorImageFile, setSponsorImageFile] = useState<File | null>(null);
  const [sponsorImagePreview, setSponsorImagePreview] = useState<string | null>(null);
  
  // Advanced Settings mapped to Flutter
  const [format, setFormat] = useState<LeagueFormat>('classic');
  const [category, setCategory] = useState<FootballCategory>('localFootball');
  const [privacy, setPrivacy] = useState<LeaguePrivacy>('public');
  const [selectedMaxTeams, setSelectedMaxTeams] = useState<number>(20);
  const [homeAwayEnabled, setHomeAwayEnabled] = useState(false);
  const [containsRewards, setContainsRewards] = useState(false);
  const [creatorParticipates, setCreatorParticipates] = useState(false);
  
  // World Cup Specific Settings
  const [worldCupFormat, setWorldCupFormat] = useState<WorldCupFormat>('fifa2022');

  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  // ── Access & Limit Check ──
  useEffect(() => {
    const unsubscribe = auth.onAuthStateChanged(async (user) => {
      if (!user) {
        router.push('/login');
        return;
      }
      setAuthUid(user.uid);
      setCheckingAccess(true);

      try {
        // Fetch User Profile for Premium Status
        const userDoc = await getDoc(doc(db, 'users', user.uid));
        const isPaid = userDoc.exists() && userDoc.data()?.isPremium === true; // Or activePlan mapping
        
        // Fetch Created Leagues Count
        const q = query(collection(db, 'leagues'), where('organizerUid', '==', user.uid));
        const snap = await getDocs(q);
        
        setIsPremium(isPaid);
        setCreatedCount(snap.size);
      } catch (err) {
        console.error("Failed to check access:", err);
      } finally {
        setCheckingAccess(false);
      }
    });
    return () => unsubscribe();
  }, [router]);

  const limitReached = !isPremium && createdCount >= FREE_LEAGUE_LIMIT;
  const supportsHomeAway = format === 'classic' || format === 'uclGroup';

  // ── Handlers ──
  const handleFormatChange = (newFormat: LeagueFormat) => {
    setFormat(newFormat);
    if (newFormat === 'worldCup') {
      setSelectedMaxTeams(worldCupFormat === 'fifa2022' ? 32 : 48);
      setHomeAwayEnabled(false);
    } else if (newFormat === 'uclGroup') {
      setSelectedMaxTeams(32);
    } else if (newFormat === 'uclSwiss') {
      setSelectedMaxTeams(36);
      setHomeAwayEnabled(false);
    } else {
      setSelectedMaxTeams(20);
    }
  };

  const handleWorldCupFormatChange = (wcFormat: WorldCupFormat) => {
    setWorldCupFormat(wcFormat);
    setSelectedMaxTeams(wcFormat === 'fifa2022' ? 32 : 48);
  };

  const handleImageChange = (e: React.ChangeEvent<HTMLInputElement>, type: 'league' | 'sponsor') => {
    const file = e.target.files?.[0];
    if (file) {
      if (type === 'league') {
        setLeagueImageFile(file);
        setLeagueImagePreview(URL.createObjectURL(file));
      } else {
        setSponsorImageFile(file);
        setSponsorImagePreview(URL.createObjectURL(file));
      }
    }
  };

  // ── Parity Utilities ──
  const deriveShareIdFromUid = (uid: string) => {
    const clean = uid.replace(/[^A-Za-z0-9]/g, '').trim();
    if (!clean) return '';
    const base = clean.length >= 8 ? clean.substring(0, 8) : clean.padEnd(8, 'X');
    return `eS${base}`;
  };

  const generateUniqueJoinCode = async (): Promise<string> => {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    for (let i = 0; i < 6; i++) {
      let code = '';
      for (let j = 0; j < 6; j++) code += chars.charAt(Math.floor(Math.random() * chars.length));
      const q = query(collection(db, 'leagues'), where('code', '==', code), limit(1));
      const snap = await getDocs(q);
      if (snap.empty) return code;
    }
    throw new Error("Couldn't create a join code. Please try again.");
  };

  // ── Submit ──
  const handleCreateLeague = async (e: React.FormEvent) => {
    e.preventDefault();
    if (limitReached) {
      router.push('/premium');
      return;
    }
    if (!name.trim()) {
      setError('League name is required.');
      return;
    }
    if (!authUid) return;

    setLoading(true);
    setError('');

    try {
      // 1. Upload Images
      let leagueImageUrl = '';
      let sponsorImageUrl = '';
      
      if (leagueImageFile) leagueImageUrl = await uploadImageToCloudinary(leagueImageFile);
      if (sponsorImageFile) sponsorImageUrl = await uploadImageToCloudinary(sponsorImageFile);

      // 2. Generate required codes & IDs
      const leagueRef = doc(collection(db, 'leagues'));
      const joinCode = await generateUniqueJoinCode();
      const organizerUserId = deriveShareIdFromUid(authUid) || authUid;
      const nowMs = Date.now();
      const effectiveHomeAway = supportsHomeAway ? homeAwayEnabled : false;
      
      // 3. Match Flutter Settings Structure
      const settings = {
        doubleRoundRobin: effectiveHomeAway,
        groupSize: 4,
        swissRounds: 5,
        worldCupFormat: format === 'worldCup' ? worldCupFormat : 'fifa2022',
        lastPulledAtMs: 0
      };

      // 4. Save League Document
      const newLeague = {
        id: leagueRef.id,
        name: name.trim(),
        masterLeagueId: '',
        description: description.trim(),
        leagueImageUrl,
        sponsorImageUrl,
        viewerCapacity: 0,
        couponsEnabled: false,
        couponDiscountPercent: 0,
        couponCount: 0,
        homeAwayEnabled: effectiveHomeAway,
        footballCategory: category,
        format,
        privacy,
        region: 'Global',
        maxTeams: selectedMaxTeams,
        season: '2026',
        organizerUid: authUid,
        organizerUserId,
        code: joinCode,
        qrPayloadOverride: '',
        settings,
        updatedAtMs: nowMs,
        version: 1,
      };

      await setDoc(leagueRef, newLeague);

      // 5. Add Creator as Member if selected
      if (creatorParticipates) {
        const membershipRef = doc(db, 'leagues', leagueRef.id, 'memberships', authUid);
        await setDoc(membershipRef, {
          id: authUid,
          leagueId: leagueRef.id,
          userId: authUid,
          teamId: null,
          role: 0, // 0 = Organizer, 1 = Member
          updatedAtMs: nowMs,
          version: 1
        });
      }

      router.push(`/leagues/${leagueRef.id}`);
    } catch (err: any) {
      console.error(err);
      setError('Failed to create league: ' + err.message);
      setLoading(false);
    }
  };

  if (checkingAccess) {
    return (
      <div className="min-h-screen bg-[#070B14] flex items-center justify-center">
        <Loader2 className="w-10 h-10 text-[#BEF264] animate-spin" />
      </div>
    );
  }

  return (
    <div className="space-y-6 max-w-6xl mx-auto pb-16">
      
      {/* ── HEADER ── */}
      <div className="flex items-center gap-4">
        <button onClick={() => router.back()} className="p-2.5 bg-[#0B1221] border border-[#1E293B] hover:border-[#2A3A52] rounded-xl transition-colors">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <div>
          <h1 className="text-2xl md:text-3xl font-black text-white tracking-tight flex items-center gap-3">
            <Trophy className="w-7 h-7 text-[#BEF264]" />
            Create League
          </h1>
          <p className="text-sm font-semibold text-gray-400 mt-1">Configure and launch a new competition</p>
        </div>
      </div>

      {/* ── ACCESS BANNER ── */}
      {limitReached ? (
        <div className="bg-amber-500/10 border border-amber-500/30 rounded-2xl p-4 flex items-start gap-4">
          <Lock className="w-6 h-6 text-amber-500 shrink-0" />
          <div className="flex-1">
            <h3 className="text-amber-500 font-black text-sm">Basic Limit Reached</h3>
            <p className="text-amber-500/80 text-xs font-semibold mt-1">
              Basic users can create up to {FREE_LEAGUE_LIMIT} leagues total. Upgrade to Pro or Elite to create more.
            </p>
          </div>
          <button onClick={() => router.push('/premium')} className="px-4 py-2 bg-amber-500 text-white text-xs font-black rounded-lg hover:brightness-110 shadow-lg">
            Upgrade Plan
          </button>
        </div>
      ) : isPremium ? (
        <div className="bg-[#BEF264]/10 border border-[#BEF264]/30 rounded-2xl p-4 flex items-center gap-4">
          <CheckCircle2 className="w-6 h-6 text-[#BEF264] shrink-0" />
          <div>
            <h3 className="text-[#BEF264] font-black text-sm">Paid Plan Active</h3>
            <p className="text-[#BEF264]/80 text-xs font-semibold mt-1">You have unlimited league creation enabled.</p>
          </div>
        </div>
      ) : (
        <div className="bg-[#1E293B]/50 border border-[#1E293B] rounded-2xl p-4 flex items-center gap-4">
          <ListOrdered className="w-6 h-6 text-gray-400 shrink-0" />
          <div>
            <h3 className="text-gray-300 font-black text-sm">Basic Access</h3>
            <p className="text-gray-400 text-xs font-semibold mt-1">
              You have used {createdCount} / {FREE_LEAGUE_LIMIT} free league slots.
            </p>
          </div>
        </div>
      )}

      {error && (
        <div className="bg-red-500/10 border border-red-500/30 text-red-500 p-4 rounded-xl flex items-center gap-3 text-sm font-bold">
          <ShieldAlert className="w-5 h-5 shrink-0" /> {error}
        </div>
      )}

      <form onSubmit={handleCreateLeague} className="grid grid-cols-1 lg:grid-cols-12 gap-6 relative">
        
        {/* ── LEFT & CENTER COLUMNS (Main Content) ── */}
        <div className="lg:col-span-8 space-y-6">
          
          {/* Section 1: Type Selection */}
          <div className="bg-[#0B1221] border border-[#1E293B] rounded-3xl p-6 shadow-xl">
            <h2 className="text-lg font-black text-white mb-4 flex items-center gap-2">
              <Trophy className="w-5 h-5 text-[#BEF264]" /> Competition Type
            </h2>
            
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <TypeCard 
                id="classic" current={format} icon={ListOrdered} 
                title="Classic League" desc="Standard points-based table" 
                onClick={() => handleFormatChange('classic')} 
              />
              <TypeCard 
                id="uclGroup" current={format} icon={LayoutGrid} 
                title="Group Stage" desc="Multiple groups into knockouts" 
                onClick={() => handleFormatChange('uclGroup')} 
              />
              <TypeCard 
                id="uclSwiss" current={format} icon={ShieldAlert} 
                title="Swiss Series" desc="Dynamic matchmaking rounds" 
                onClick={() => handleFormatChange('uclSwiss')} 
              />
              
              {/* Premium World Cup Card */}
              <div 
                onClick={() => handleFormatChange('worldCup')}
                className={`cursor-pointer rounded-2xl p-5 border-[1.5px] transition-all relative overflow-hidden ${
                  format === 'worldCup' 
                    ? 'border-amber-500 bg-amber-500/10 shadow-[0_0_20px_rgba(245,158,11,0.15)]' 
                    : 'border-[#1E293B] bg-[#070B14] hover:border-amber-500/50'
                }`}
              >
                <div className="flex items-start gap-4">
                  <div className={`p-3 rounded-xl ${format === 'worldCup' ? 'bg-amber-500/20 text-amber-500' : 'bg-[#1E293B] text-gray-500'}`}>
                    <Globe className="w-6 h-6" />
                  </div>
                  <div>
                    <div className="flex items-center gap-2">
                      <h3 className={`font-black ${format === 'worldCup' ? 'text-amber-500' : 'text-white'}`}>World Cup</h3>
                      <span className="px-2 py-0.5 rounded text-[9px] font-black bg-amber-500/20 text-amber-500 border border-amber-500/30">PREMIUM</span>
                    </div>
                    <p className="text-xs text-gray-400 font-medium mt-1">Official FIFA format with group stage and knockouts.</p>
                  </div>
                </div>
              </div>
            </div>

            {/* World Cup Sub-Format */}
            {format === 'worldCup' && (
              <div className="mt-6 pt-6 border-t border-[#1E293B]">
                <h3 className="text-sm font-black text-white mb-3 flex items-center gap-2">
                  <Globe className="w-4 h-4 text-amber-500" /> World Cup Format
                </h3>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                  <WcFormatCard id="fifa2022" current={worldCupFormat} title="FIFA 2022 Format" desc="32 Teams • 8 Groups of 4" onClick={() => handleWorldCupFormatChange('fifa2022')} />
                  <WcFormatCard id="fifa2026" current={worldCupFormat} title="FIFA 2026 Format" desc="48 Teams • 12 Groups of 4" onClick={() => handleWorldCupFormatChange('fifa2026')} />
                </div>
              </div>
            )}
          </div>

          {/* Section 2: Details & Images */}
          <div className="bg-[#0B1221] border border-[#1E293B] rounded-3xl p-6 shadow-xl">
            <h2 className="text-lg font-black text-white mb-6 flex items-center gap-2">
              <ImageIcon className="w-5 h-5 text-[#BEF264]" /> League Details
            </h2>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mb-6">
              <div className="space-y-2">
                <label className="text-sm font-bold text-gray-300">League Banner</label>
                <div 
                  onClick={() => leagueImageRef.current?.click()}
                  className="w-full h-32 rounded-2xl border-2 border-dashed border-[#1E293B] hover:border-[#BEF264] bg-[#070B14] flex flex-col items-center justify-center cursor-pointer transition-all relative overflow-hidden group"
                >
                  {leagueImagePreview ? (
                    <img src={leagueImagePreview} className="w-full h-full object-cover" alt="League" />
                  ) : (
                    <>
                      <ImageIcon className="w-8 h-8 text-gray-500 group-hover:text-[#BEF264] mb-2 transition-colors" />
                      <span className="text-xs text-gray-500 font-bold group-hover:text-[#BEF264]">Upload Banner</span>
                    </>
                  )}
                </div>
                <input type="file" ref={leagueImageRef} onChange={(e) => handleImageChange(e, 'league')} accept="image/*" className="hidden" />
              </div>

              <div className="space-y-2">
                <label className="text-sm font-bold text-gray-300">Sponsor Logo (Optional)</label>
                <div 
                  onClick={() => sponsorImageRef.current?.click()}
                  className="w-full h-32 rounded-2xl border-2 border-dashed border-[#1E293B] hover:border-[#BEF264] bg-[#070B14] flex flex-col items-center justify-center cursor-pointer transition-all relative overflow-hidden group"
                >
                  {sponsorImagePreview ? (
                    <img src={sponsorImagePreview} className="w-full h-full object-contain p-2 bg-white" alt="Sponsor" />
                  ) : (
                    <>
                      <ImageIcon className="w-8 h-8 text-gray-500 group-hover:text-[#BEF264] mb-2 transition-colors" />
                      <span className="text-xs text-gray-500 font-bold group-hover:text-[#BEF264]">Upload Sponsor Logo</span>
                    </>
                  )}
                </div>
                <input type="file" ref={sponsorImageRef} onChange={(e) => handleImageChange(e, 'sponsor')} accept="image/*" className="hidden" />
              </div>
            </div>

            <div className="space-y-4">
              <div>
                <label className="block text-sm font-bold text-gray-300 mb-2">League Name *</label>
                <input
                  type="text" value={name} onChange={(e) => setName(e.target.value)} required disabled={limitReached}
                  className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl p-3.5 text-sm font-bold text-white focus:border-[#BEF264] focus:ring-1 focus:ring-[#BEF264] transition-all outline-none"
                  placeholder="e.g. Summer Championship"
                />
              </div>

              <div>
                <label className="block text-sm font-bold text-gray-300 mb-2">Description</label>
                <textarea
                  value={description} onChange={(e) => setDescription(e.target.value)} rows={3} disabled={limitReached}
                  className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl p-3.5 text-sm font-medium text-white focus:border-[#BEF264] focus:ring-1 focus:ring-[#BEF264] transition-all outline-none resize-none"
                  placeholder="Rules, schedule, info..."
                />
              </div>
            </div>
          </div>
        </div>

        {/* ── RIGHT COLUMN (Settings & Submit) ── */}
        <div className="lg:col-span-4 space-y-6">
          
          <div className="bg-[#0B1221] border border-[#1E293B] rounded-3xl p-6 shadow-xl sticky top-24">
            <h2 className="text-lg font-black text-white mb-6">Configuration</h2>
            
            <div className="space-y-5">
              
              {/* Category */}
              <div>
                <label className="block text-xs font-bold text-gray-400 uppercase tracking-widest mb-2">Category</label>
                <select 
                  value={category} onChange={(e) => setCategory(e.target.value as FootballCategory)} disabled={limitReached}
                  className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl p-3 text-sm font-bold text-white focus:border-[#BEF264] outline-none"
                >
                  {FOOTBALL_CATEGORIES.map(c => <option key={c.id} value={c.id}>{c.label}</option>)}
                </select>
              </div>

              {/* Privacy */}
              <div>
                <label className="block text-xs font-bold text-gray-400 uppercase tracking-widest mb-2">Privacy</label>
                <div className="grid grid-cols-2 gap-2">
                  <button type="button" onClick={() => setPrivacy('public')} disabled={limitReached} className={`py-2.5 rounded-lg text-xs font-bold border transition-colors ${privacy === 'public' ? 'bg-[#BEF264]/10 border-[#BEF264] text-[#BEF264]' : 'bg-[#070B14] border-[#1E293B] text-gray-500 hover:border-gray-600'}`}>Public</button>
                  <button type="button" onClick={() => setPrivacy('private')} disabled={limitReached} className={`py-2.5 rounded-lg text-xs font-bold border transition-colors ${privacy === 'private' ? 'bg-[#BEF264]/10 border-[#BEF264] text-[#BEF264]' : 'bg-[#070B14] border-[#1E293B] text-gray-500 hover:border-gray-600'}`}>Private</button>
                </div>
              </div>

              {/* Max Teams */}
              <div>
                <label className="block text-xs font-bold text-gray-400 uppercase tracking-widest mb-2">Max Teams</label>
                <input 
                  type="number" value={selectedMaxTeams} onChange={(e) => setSelectedMaxTeams(parseInt(e.target.value) || 20)}
                  disabled={format === 'worldCup' || limitReached}
                  className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl p-3 text-sm font-bold text-white focus:border-[#BEF264] outline-none disabled:opacity-50"
                />
                {format === 'worldCup' && <p className="text-[10px] text-amber-500 mt-1 font-bold">Locked by World Cup Format</p>}
              </div>

              {/* Toggles */}
              <div className="space-y-3 pt-4 border-t border-[#1E293B]">
                <ToggleRow 
                  label="Home & Away Matches" 
                  desc="Each team plays twice"
                  checked={homeAwayEnabled} 
                  onChange={setHomeAwayEnabled} 
                  disabled={!supportsHomeAway || limitReached} 
                />
                <ToggleRow 
                  label="League Contains Rewards" 
                  desc="Prize pool or trophies"
                  checked={containsRewards} 
                  onChange={setContainsRewards} 
                  disabled={limitReached} 
                />
                <ToggleRow 
                  label="I Will Participate" 
                  desc="Join automatically as a team"
                  checked={creatorParticipates} 
                  onChange={setCreatorParticipates} 
                  disabled={limitReached} 
                />
              </div>
            </div>

            {/* Submit Button */}
            <div className="mt-8 pt-6 border-t border-[#1E293B]">
              {limitReached ? (
                <button type="button" onClick={() => router.push('/premium')} className="w-full py-4 bg-amber-500 text-white font-black rounded-xl hover:brightness-110 transition-all flex items-center justify-center gap-2 shadow-lg shadow-amber-500/20">
                  <CreditCard className="w-5 h-5" /> Upgrade Plan
                </button>
              ) : (
                <button type="submit" disabled={loading || !name.trim()} className="w-full py-4 bg-[#BEF264] text-[#0F172A] font-black rounded-xl hover:brightness-110 transition-all disabled:opacity-50 flex items-center justify-center gap-2 shadow-lg shadow-[#BEF264]/20">
                  {loading ? <Loader2 className="w-5 h-5 animate-spin" /> : <Trophy className="w-5 h-5" />}
                  {format === 'worldCup' ? 'CREATE WORLD CUP' : 'CREATE LEAGUE'}
                </button>
              )}
            </div>
          </div>
        </div>
      </form>
    </div>
  );
}

// ── Shared UI Components ──

function TypeCard({ id, current, icon: Icon, title, desc, onClick }: any) {
  const selected = current === id;
  return (
    <div 
      onClick={onClick}
      className={`cursor-pointer rounded-2xl p-5 border-[1.5px] transition-all flex items-start gap-4 ${
        selected ? 'border-[#BEF264] bg-[#BEF264]/5 shadow-[0_0_20px_rgba(190,242,100,0.1)]' : 'border-[#1E293B] bg-[#070B14] hover:border-gray-600'
      }`}
    >
      <div className={`p-3 rounded-xl ${selected ? 'bg-[#BEF264]/20 text-[#BEF264]' : 'bg-[#1E293B] text-gray-500'}`}>
        <Icon className="w-6 h-6" />
      </div>
      <div>
        <h3 className={`font-black ${selected ? 'text-[#BEF264]' : 'text-white'}`}>{title}</h3>
        <p className="text-xs text-gray-400 font-medium mt-1">{desc}</p>
      </div>
    </div>
  );
}

function WcFormatCard({ id, current, title, desc, onClick }: any) {
  const selected = current === id;
  return (
    <div 
      onClick={onClick}
      className={`cursor-pointer rounded-xl p-4 border transition-all ${
        selected ? 'border-amber-500 bg-amber-500/10' : 'border-[#1E293B] bg-[#070B14] hover:border-amber-500/50'
      }`}
    >
      <h4 className={`text-sm font-black ${selected ? 'text-amber-500' : 'text-white'}`}>{title}</h4>
      <p className="text-xs font-bold text-gray-400 mt-1">{desc}</p>
    </div>
  );
}

function ToggleRow({ label, desc, checked, onChange, disabled }: any) {
  return (
    <div className={`flex items-center justify-between ${disabled ? 'opacity-50 pointer-events-none' : ''}`}>
      <div>
        <h4 className="text-sm font-bold text-white">{label}</h4>
        <p className="text-[10px] font-bold text-gray-500">{desc}</p>
      </div>
      <button 
        type="button" 
        onClick={() => onChange(!checked)}
        className={`w-12 h-6 rounded-full relative transition-colors ${checked ? 'bg-[#BEF264]' : 'bg-[#1E293B]'}`}
      >
        <div className={`w-4 h-4 rounded-full bg-white absolute top-1 transition-all ${checked ? 'left-7' : 'left-1'}`} />
      </button>
    </div>
  );
}
