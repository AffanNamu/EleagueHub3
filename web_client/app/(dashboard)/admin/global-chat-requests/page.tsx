'use client';

import { useState, useEffect } from 'react';
import { collection, query, where, onSnapshot, updateDoc, doc } from 'firebase/firestore';
import { auth, db } from '@/lib/firebase';
import { Glass } from '@/components/ui/Glass';
import { Loader2, Shield, Check, X, Search } from 'lucide-react';
import { useRouter } from 'next/navigation';

export default function AdminGlobalChatRequestsScreen() {
  const [requests, setRequests] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const router = useRouter();

  const SUPER_ADMIN_UID = 'a0JDUelQW3TEyoXTm4ESuGi7ndq1';

  useEffect(() => {
    if (!auth.currentUser) return;
    
    // Hardcoded block just like _isSuperAdmin in Flutter
    if (auth.currentUser.uid !== SUPER_ADMIN_UID) {
      router.push('/leagues');
      return;
    }

    const q = query(
      collection(db, 'globalChatRequests'),
      where('status', '==', 'pending')
    );

    const unsubscribe = onSnapshot(q, (snapshot) => {
      const docs = snapshot.docs.map(d => ({ id: d.id, ...d.data() }));
      setRequests(docs);
      setLoading(false);
    });

    return () => unsubscribe();
  }, [router]);

  const handleStatusUpdate = async (id: string, status: 'approved' | 'rejected') => {
    try {
      await updateDoc(doc(db, 'globalChatRequests', id), {
        status,
        updatedAtMs: Date.now()
      });
    } catch (err) {
      alert("Failed to update status");
    }
  };

  const filteredRequests = requests.filter(r => 
    (r.userName?.toLowerCase() || '').includes(search.toLowerCase()) || 
    r.id.toLowerCase().includes(search.toLowerCase())
  );

  if (loading) return <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 text-brand-lime animate-spin" /></div>;

  return (
    <div className="space-y-6 max-w-4xl mx-auto pb-10">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-white flex items-center gap-2">
          <Shield className="w-6 h-6 text-brand-lime" />
          Global Chat Requests
        </h1>
      </div>

      <Glass className="p-4 flex items-center gap-4">
        <div className="p-3 bg-brand-surface rounded-full">
          <Shield className="w-6 h-6 text-brand-lime" />
        </div>
        <div>
          <h2 className="font-bold text-white">Pending Approvals</h2>
          <p className="text-sm text-gray-400">{requests.length} users waiting for access.</p>
        </div>
      </Glass>

      <div className="relative">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-5 h-5 text-gray-400" />
        <input 
          type="text"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search by user name or ID..."
          className="w-full pl-10 p-3 bg-brand-surface border border-white/10 rounded-xl text-white focus:outline-none focus:border-brand-lime"
        />
      </div>

      <div className="space-y-4">
        {filteredRequests.length === 0 ? (
          <div className="text-center py-10 text-gray-500">No pending requests found.</div>
        ) : (
          filteredRequests.map(req => (
            <Glass key={req.id} className="p-4 flex flex-col md:flex-row md:items-center justify-between gap-4">
              <div className="flex items-center gap-3">
                {req.userPhoto ? (
                  <img src={req.userPhoto} className="w-12 h-12 rounded-full object-cover" alt="" />
                ) : (
                  <div className="w-12 h-12 rounded-full bg-brand-surface flex items-center justify-center">
                    <Shield className="w-6 h-6 text-gray-400" />
                  </div>
                )}
                <div>
                  <h3 className="font-bold text-white">{req.userName || 'Unknown User'}</h3>
                  <p className="text-xs text-gray-400 font-mono">{req.id}</p>
                </div>
              </div>

              <div className="flex items-center gap-2">
                <button 
                  onClick={() => handleStatusUpdate(req.id, 'approved')}
                  className="flex-1 md:flex-none px-4 py-2 bg-brand-lime text-brand-navy font-bold rounded-lg hover:bg-brand-lime/90 flex items-center justify-center gap-2"
                >
                  <Check className="w-4 h-4" /> Approve
                </button>
                <button 
                  onClick={() => handleStatusUpdate(req.id, 'rejected')}
                  className="flex-1 md:flex-none px-4 py-2 bg-brand-surface border border-brand-red/30 text-brand-red font-bold rounded-lg hover:bg-brand-red/10 flex items-center justify-center gap-2"
                >
                  <X className="w-4 h-4" /> Reject
                </button>
              </div>
            </Glass>
          ))
        )}
      </div>
    </div>
  );
}
