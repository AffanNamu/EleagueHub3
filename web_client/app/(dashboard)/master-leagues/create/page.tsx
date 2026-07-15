'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { collection, doc, setDoc, getDocs, query, where } from 'firebase/firestore';
import { db, auth } from '@/lib/firebase';
import { useEntitlements } from '@/hooks/useEntitlements';
import { Glass } from '@/components/ui/Glass';
import { Loader2, ArrowLeft, Network, ShieldCheck, Star, ShieldAlert } from 'lucide-react';
import { MasterLeaguePlan } from '@/types/masterLeague';

export default function CreateMasterLeagueScreen() {
  const router = useRouter();
  const { activePlan, loading: entitlementsLoading } = useEntitlements();
  
  const [hubName, setHubName] = useState('');
  const [description, setDescription] = useState('');
  const [selectedPlan, setSelectedPlan] = useState<MasterLeaguePlan>('basic');
  
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleCreateHub = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!auth.currentUser) return;
    if (!hubName.trim()) return setError('Hub name is required.');

    if (selectedPlan !== 'basic' && activePlan !== selectedPlan) {
      return setError(`You must upgrade to the ${selectedPlan.toUpperCase()} plan to create this tier of Hub.`);
    }

    setLoading(true);
    setError('');

    try {
      const uid = auth.currentUser.uid;
      const hubsQuery = query(collection(db, 'master_leagues'), where('ownerId', '==', uid));
      const existingHubs = await getDocs(hubsQuery);
      
      if (activePlan === 'basic' && existingHubs.size >= 1) {
         throw new Error("Basic Plan is limited to 1 Master League Hub. Please upgrade to create more.");
      }

      const hubRef = doc(collection(db, 'master_leagues'));
      const nowMs = Date.now();

      await setDoc(hubRef, {
        id: hubRef.id,
        ownerId: uid,
        ownerUid: uid,
        name: hubName.trim(),
        description: description.trim(),
        plan: selectedPlan,
        followersCount: 0,
        memberIds: [uid],
        createdAtMs: nowMs,
        isVerifiedOrganizer: false,
        verificationStatus: 'none',
        organizerProfile: {
          name: hubName.trim(),
          logoUrl: auth.currentUser.photoURL || '',
          isVerified: false
        }
      });

      alert("Master League Hub created successfully!");
      router.push(`/master-leagues/${hubRef.id}`);
    } catch (err: any) {
      console.error(err);
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  if (entitlementsLoading) return <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 animate-spin text-[#38BDF8]" /></div>;

  return (
    <div className="space-y-6 max-w-5xl mx-auto pb-10">
      <div className="flex items-center gap-4">
        <button onClick={() => router.back()} className="p-2 bg-brand-surface hover:bg-white/10 rounded-xl transition-colors">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <div>
          <h1 className="text-2xl md:text-3xl font-bold text-[#38BDF8] flex items-center gap-2">
            <Network className="w-6 h-6" /> Create Master League
          </h1>
          <p className="text-gray-400 mt-1">Establish your eSports Organizer Hub.</p>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-1 space-y-4">
          <h2 className="font-bold text-white mb-2">Select Hub Tier</h2>
          
          <div 
            onClick={() => setSelectedPlan('basic')}
            className={`p-4 rounded-xl border cursor-pointer transition-all ${selectedPlan === 'basic' ? 'bg-[#38BDF8]/10 border-[#38BDF8] shadow-lg shadow-[#38BDF8]/10' : 'bg-brand-surface border-white/10 hover:border-[#38BDF8]/50'}`}
          >
            <div className="flex items-center gap-2 mb-2">
              <ShieldCheck className={`w-5 h-5 ${selectedPlan === 'basic' ? 'text-[#38BDF8]' : 'text-gray-500'}`} />
              <span className="font-bold text-white">Basic (Free)</span>
            </div>
            <p className="text-xs text-gray-400 mb-2">Perfect for local communities.</p>
            <ul className="text-[10px] text-gray-400 space-y-1 ml-4 list-disc">
              <li>Max 16 Teams per League</li>
              <li>Unlisted (Invite Only)</li>
              <li>1 Hub limit</li>
            </ul>
          </div>

          <div 
            onClick={() => setSelectedPlan('pro')}
            className={`p-4 rounded-xl border cursor-pointer transition-all ${selectedPlan === 'pro' ? 'bg-brand-lime/10 border-brand-lime shadow-lg shadow-brand-lime/10' : 'bg-brand-surface border-white/10 hover:border-brand-lime/50'}`}
          >
            <div className="flex items-center gap-2 mb-2">
              <Star className={`w-5 h-5 ${selectedPlan === 'pro' ? 'text-brand-lime' : 'text-gray-500'}`} />
              <span className="font-bold text-white">Pro Organizer</span>
            </div>
            <p className="text-xs text-gray-400 mb-2">For growing organizations.</p>
            <ul className="text-[10px] text-gray-400 space-y-1 ml-4 list-disc">
              <li>Max 24 Teams per League</li>
              <li>Public Discovery</li>
              <li>Official Badges</li>
            </ul>
            {activePlan !== 'pro' && activePlan !== 'elite' && (
               <div className="mt-3 text-center w-full py-1.5 bg-brand-lime/20 text-brand-lime rounded text-[10px] font-bold uppercase tracking-wider">Requires Payment</div>
            )}
          </div>
        </div>

        <div className="lg:col-span-2">
          <Glass className="p-6 md:p-8 h-full">
            {error && (
              <div className="flex items-center gap-2 bg-brand-red/20 border border-brand-red text-brand-red p-4 rounded-xl mb-6">
                <ShieldAlert className="w-5 h-5 flex-shrink-0" />
                <span className="text-sm">{error}</span>
              </div>
            )}

            <form onSubmit={handleCreateHub} className="space-y-6">
              <div>
                <label className="block text-sm font-bold text-gray-300 mb-1">Hub Name (Your Brand) *</label>
                <input 
                  type="text" value={hubName} onChange={(e) => setHubName(e.target.value)} required
                  placeholder="e.g. Continental eSports"
                  className="w-full bg-brand-surface border border-white/10 rounded-xl p-4 text-white focus:border-[#38BDF8]"
                />
              </div>

              <div>
                <label className="block text-sm font-bold text-gray-300 mb-1">Hub Description</label>
                <textarea 
                  value={description} onChange={(e) => setDescription(e.target.value)} rows={3}
                  placeholder="Tell followers about your organization..."
                  className="w-full bg-brand-surface border border-white/10 rounded-xl p-4 text-white focus:border-[#38BDF8] resize-none"
                />
              </div>

              <div className="pt-6 border-t border-white/5">
                <button
                  type="submit"
                  disabled={loading || !hubName.trim()}
                  className="w-full py-4 bg-[#38BDF8] text-brand-navy font-black rounded-xl hover:bg-[#38BDF8]/90 transition-all disabled:opacity-50 flex items-center justify-center gap-2 shadow-lg shadow-[#38BDF8]/20"
                >
                  {loading ? <Loader2 className="w-5 h-5 animate-spin" /> : <Network className="w-5 h-5" />}
                  {selectedPlan !== 'basic' && activePlan !== selectedPlan ? 'Proceed to Payment' : 'Initialize Hub'}
                </button>
              </div>
            </form>
          </Glass>
        </div>
      </div>
    </div>
  );
}
