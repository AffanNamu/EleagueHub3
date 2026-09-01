'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { auth } from '@/lib/firebase';
import { useDiscussionThreads } from '@/hooks/useDiscovery';
import { createDiscussionThreadWeb } from '@/lib/discovery/discoveryRepository';
import { Glass } from '@/components/ui/Glass';
import { ArrowLeft, Loader2, Plus, MessageSquare, User, X } from 'lucide-react';

function timeAgo(ms: number) {
  const diff = Math.floor((Date.now() - ms) / 60000);
  if (diff < 1) return 'now';
  if (diff < 60) return `${diff}m`;
  if (diff < 1440) return `${Math.floor(diff / 60)}h`;
  return `${Math.floor(diff / 1440)}d`;
}

export default function DiscussionsListScreen() {
  const router = useRouter();
  const { threads, loading } = useDiscussionThreads();

  const [modalOpen, setModalOpen] = useState(false);
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');

  const handleCreate = async () => {
    if (!title.trim()) return setError('Please add a title.');
    const user = auth.currentUser;
    if (!user) return router.push('/login');

    setSubmitting(true);
    setError('');
    try {
      await createDiscussionThreadWeb({
        authorId: user.uid,
        authorDisplayName: user.displayName || 'User',
        authorPhotoUrl: user.photoURL || '',
        title,
        body
      });
      setModalOpen(false);
      setTitle(''); setBody('');
    } catch (err: any) {
      setError(err.message || 'Creation failed.');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="max-w-4xl mx-auto space-y-6 pb-20 px-4 sm:px-6 mt-4 relative">
      <div className="flex items-center gap-4 mb-6">
        <button onClick={() => router.back()} className="p-2.5 bg-[#0B1221] border border-[#1E293B] hover:border-[#2A3A52] rounded-xl transition-colors">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <h1 className="text-xl md:text-2xl font-black text-white">Discussions</h1>
      </div>

      {loading ? (
        <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 animate-spin text-green-500" /></div>
      ) : threads.length === 0 ? (
        <div className="p-16 text-center border border-[#1E293B] bg-[#0B1221] rounded-3xl">
          <p className="text-gray-500 font-bold">No discussions yet. Start the first one.</p>
        </div>
      ) : (
        <div className="space-y-3">
          {threads.map(t => (
            <Glass key={t.threadId} onClick={() => router.push(`/discovery/community/discussions/${t.threadId}`)} className="p-4 bg-[#0B1221] border-[#1E293B] hover:bg-white/5 hover:border-white/10 transition-colors cursor-pointer rounded-2xl">
              <div className="flex items-center gap-2 mb-2">
                <div className="w-6 h-6 rounded-full bg-[#1E293B] overflow-hidden shrink-0 flex items-center justify-center">
                  {t.authorPhotoUrl ? <img src={t.authorPhotoUrl} className="w-full h-full object-cover" /> : <User className="w-3 h-3 text-gray-500" />}
                </div>
                <span className="text-xs font-bold text-gray-500 truncate flex-1">{t.authorDisplayName}</span>
                <span className="text-[10px] font-bold text-gray-500">{timeAgo(t.lastReplyAtMs)}</span>
              </div>
              <h3 className="text-base font-black text-white leading-tight mb-3 line-clamp-2">{t.title}</h3>
              <div className="flex items-center gap-1.5 text-xs font-bold text-gray-500">
                <MessageSquare className="w-3.5 h-3.5" /> {t.replyCount} {t.replyCount === 1 ? 'reply' : 'replies'}
              </div>
            </Glass>
          ))}
        </div>
      )}

      {/* FAB */}
      {auth.currentUser && (
        <button onClick={() => setModalOpen(true)} className="fixed bottom-20 right-6 md:right-10 w-14 h-14 bg-[#BEF264] text-[#0F172A] rounded-full shadow-2xl flex items-center justify-center hover:scale-110 transition-transform z-40">
          <Plus className="w-6 h-6" />
        </button>
      )}

      {/* Modal */}
      {modalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-sm">
          <Glass className="w-full max-w-lg bg-[#0F172A] border border-[#1E293B] rounded-3xl p-6 shadow-2xl">
            <div className="flex justify-between items-center mb-6">
              <h2 className="text-xl font-black text-white">Start a Discussion</h2>
              <button onClick={() => !submitting && setModalOpen(false)} className="text-gray-500 hover:text-white"><X className="w-5 h-5"/></button>
            </div>
            
            {error && <p className="text-xs font-bold text-red-500 mb-3">{error}</p>}

            <input value={title} onChange={e => setTitle(e.target.value)} disabled={submitting} placeholder="Title" maxLength={140} className="w-full bg-[#0B1221] border border-[#1E293B] rounded-xl p-4 text-white outline-none focus:border-[#BEF264] mb-3" />
            <textarea value={body} onChange={e => setBody(e.target.value)} disabled={submitting} placeholder="Share more detail (optional)" maxLength={4000} rows={5} className="w-full bg-[#0B1221] border border-[#1E293B] rounded-xl p-4 text-white outline-none focus:border-[#BEF264] mb-6 resize-none" />

            <button onClick={handleCreate} disabled={submitting} className="w-full py-4 bg-[#BEF264] text-[#0F172A] font-black rounded-xl hover:brightness-110 disabled:opacity-50 flex items-center justify-center">
              {submitting ? <Loader2 className="w-5 h-5 animate-spin" /> : 'Post Discussion'}
            </button>
          </Glass>
        </div>
      )}
    </div>
  );
}
