'use client';

import { useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { auth } from '@/lib/firebase';
import { useDiscussionDetail } from '@/hooks/useDiscovery';
import { createDiscussionReplyWeb, deleteDiscussionThreadWeb, deleteDiscussionReplyWeb } from '@/lib/discovery/discoveryRepository';
import { Glass } from '@/components/ui/Glass';
import { ArrowLeft, Loader2, Send, User, Trash2, X } from 'lucide-react';

function timeAgo(ms: number) {
  const diff = Math.floor((Date.now() - ms) / 60000);
  if (diff < 1) return 'now';
  if (diff < 60) return `${diff}m`;
  if (diff < 1440) return `${Math.floor(diff / 60)}h`;
  return `${Math.floor(diff / 1440)}d`;
}

export default function DiscussionDetailScreen() {
  const router = useRouter();
  const params = useParams();
  const threadId = params.threadId as string;

  const { thread, replies, loading } = useDiscussionDetail(threadId);
  
  const [text, setText] = useState('');
  const [sending, setSending] = useState(false);
  const selfUid = auth.currentUser?.uid || '';

  if (loading) return <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 animate-spin text-green-500" /></div>;
  if (!thread) return <div className="text-center py-20 font-bold text-gray-500">This discussion is no longer available.</div>;

  const handleSend = async () => {
    if (!text.trim() || sending) return;
    if (!selfUid) return router.push('/login');
    
    setSending(true);
    try {
      await createDiscussionReplyWeb({
        threadId,
        authorId: selfUid,
        authorDisplayName: auth.currentUser!.displayName || 'User',
        authorPhotoUrl: auth.currentUser!.photoURL || '',
        text
      });
      setText('');
    } catch (err: any) {
      alert(err.message);
    } finally {
      setSending(false);
    }
  };

  const handleDeleteThread = async () => {
    if (confirm("Delete this discussion? This cannot be undone.")) {
      await deleteDiscussionThreadWeb(threadId, selfUid);
      router.back();
    }
  };

  return (
    <div className="flex flex-col h-[calc(100vh-5rem)] max-w-3xl mx-auto bg-[#070B14] md:border-x md:border-[#1E293B]">
      {/* Header */}
      <div className="flex items-center gap-3 p-4 border-b border-[#1E293B] bg-[#0B1221]">
        <button onClick={() => router.back()} className="w-10 h-10 flex items-center justify-center rounded-xl bg-[#1E293B]/50 hover:bg-[#1E293B] text-white transition-colors">
          <ArrowLeft className="w-5 h-5" />
        </button>
        <h1 className="text-lg font-black text-white">Discussion</h1>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto p-4 custom-scrollbar">
        <Glass className="p-5 bg-[#0B1221] border-[#1E293B] rounded-2xl mb-8 shadow-xl">
          <div className="flex items-center justify-between mb-4">
            <div className="flex items-center gap-3">
              <div className="w-8 h-8 rounded-full bg-[#1E293B] flex items-center justify-center overflow-hidden shrink-0">
                {thread.authorPhotoUrl ? <img src={thread.authorPhotoUrl} className="w-full h-full object-cover" /> : <User className="w-4 h-4 text-gray-500" />}
              </div>
              <div>
                <div className="text-sm font-black text-white">{thread.authorDisplayName || 'User'}</div>
                <div className="text-xs font-bold text-gray-500">{timeAgo(thread.createdAtMs)}</div>
              </div>
            </div>
            {thread.authorId === selfUid && (
              <button onClick={handleDeleteThread} className="p-2 text-gray-500 hover:text-red-500 transition-colors"><Trash2 className="w-4 h-4"/></button>
            )}
          </div>
          <h1 className="text-xl font-black text-white leading-tight mb-3">{thread.title}</h1>
          {thread.body && <p className="text-sm font-medium text-gray-300 whitespace-pre-wrap leading-relaxed">{thread.body}</p>}
        </Glass>

        <h3 className="text-sm font-black text-white mb-4">{thread.replyCount} {thread.replyCount === 1 ? 'Reply' : 'Replies'}</h3>
        
        {replies.length === 0 ? (
          <div className="text-center font-bold text-gray-500 py-8">No replies yet. Be the first to respond.</div>
        ) : (
          <div className="space-y-4">
            {replies.map(r => (
              <Glass key={r.replyId} className="p-4 bg-[#0B1221] border-[#1E293B] rounded-2xl">
                <div className="flex items-center justify-between mb-2">
                  <div className="flex items-center gap-2">
                    <div className="w-6 h-6 rounded-full bg-[#1E293B] flex items-center justify-center overflow-hidden shrink-0">
                      {r.authorPhotoUrl ? <img src={r.authorPhotoUrl} className="w-full h-full object-cover" /> : <User className="w-3 h-3 text-gray-500" />}
                    </div>
                    <span className="text-xs font-black text-white">{r.authorDisplayName || 'User'}</span>
                    <span className="text-[10px] font-bold text-gray-500">{timeAgo(r.createdAtMs)}</span>
                  </div>
                  {r.authorId === selfUid && (
                    <button onClick={() => deleteDiscussionReplyWeb(threadId, r.replyId, selfUid)} className="text-gray-500 hover:text-red-500"><X className="w-3.5 h-3.5"/></button>
                  )}
                </div>
                <p className="text-sm font-medium text-gray-300 leading-relaxed whitespace-pre-wrap">{r.text}</p>
              </Glass>
            ))}
          </div>
        )}
      </div>

      {/* Reply Input */}
      <div className="p-4 bg-[#0B1221] border-t border-[#1E293B] flex items-center gap-3">
        <input 
          value={text} onChange={e => setText(e.target.value)} onKeyDown={e => e.key === 'Enter' && handleSend()}
          disabled={sending} placeholder="Write a reply..."
          className="flex-1 bg-[#1E293B]/50 border border-white/5 rounded-xl px-4 py-3 text-sm font-semibold text-white outline-none focus:border-[#BEF264]" 
        />
        <button onClick={handleSend} disabled={sending || !text.trim()} className="w-12 h-12 flex items-center justify-center rounded-xl bg-[#BEF264] text-[#0F172A] disabled:opacity-50 hover:brightness-110 shrink-0">
          {sending ? <Loader2 className="w-5 h-5 animate-spin" /> : <Send className="w-5 h-5" />}
        </button>
      </div>
    </div>
  );
}
