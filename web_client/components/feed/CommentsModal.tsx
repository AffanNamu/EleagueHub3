'use client';

import { useEffect, useState } from 'react';
import { auth } from '@/lib/firebase';
import { subscribeToCommentsWeb, addCommentWeb, deleteCommentWeb, PublicPostComment } from '@/lib/feed/publicFeedRepository';
import { Glass } from '@/components/ui/Glass';
import { X, Send, Loader2, User } from 'lucide-react';

// NEW: web counterpart to lib/features/feed/presentation/widgets/comments_sheet.dart.
// There was previously no comments UI on web at all.

function timeAgo(ms: number) {
  const diff = Math.floor((Date.now() - ms) / 60000);
  if (diff < 1) return 'now';
  if (diff < 60) return `${diff}m`;
  if (diff < 1440) return `${Math.floor(diff / 60)}h`;
  return `${Math.floor(diff / 1440)}d`;
}

interface CommentsModalProps {
  postId: string;
  onClose: () => void;
}

export function CommentsModal({ postId, onClose }: CommentsModalProps) {
  const [comments, setComments] = useState<PublicPostComment[]>([]);
  const [loading, setLoading] = useState(true);
  const [text, setText] = useState('');
  const [sending, setSending] = useState(false);
  const [error, setError] = useState('');

  const selfUid = auth.currentUser?.uid || '';

  useEffect(() => {
    const unsub = subscribeToCommentsWeb(postId, (data) => {
      setComments(data);
      setLoading(false);
    });
    return () => unsub();
  }, [postId]);

  const handleSend = async () => {
    const trimmed = text.trim();
    if (!trimmed || sending) return;
    const user = auth.currentUser;
    if (!user) return;

    setSending(true);
    setError('');
    try {
      await addCommentWeb({
        postId,
        authorId: user.uid,
        authorDisplayName: user.displayName || 'User',
        authorPhotoUrl: user.photoURL || '',
        text: trimmed,
      });
      setText('');
    } catch (err: any) {
      setError(err.message || 'Failed to post comment.');
    } finally {
      setSending(false);
    }
  };

  const handleDelete = async (commentId: string) => {
    try {
      await deleteCommentWeb(postId, commentId, selfUid);
    } catch (err: any) {
      alert(err.message);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-sm">
      <Glass className="w-full max-w-lg bg-[#0F172A] border border-[#1E293B] rounded-3xl shadow-2xl flex flex-col max-h-[80vh]">
        <div className="flex justify-between items-center p-5 border-b border-[#1E293B] shrink-0">
          <h2 className="text-lg font-black text-white">Comments</h2>
          <button onClick={onClose} className="text-gray-500 hover:text-white">
            <X className="w-5 h-5" />
          </button>
        </div>

        <div className="flex-1 overflow-y-auto p-4 space-y-3">
          {loading ? (
            <div className="flex justify-center py-10"><Loader2 className="w-6 h-6 animate-spin text-[#BEF264]" /></div>
          ) : comments.length === 0 ? (
            <p className="text-center text-sm font-bold text-gray-500 py-10">No comments yet. Be the first to say something.</p>
          ) : (
            comments.map((c) => (
              <div key={c.commentId} className="flex items-start gap-3">
                <div className="w-8 h-8 rounded-full bg-[#1E293B] flex items-center justify-center overflow-hidden shrink-0">
                  {c.authorPhotoUrl ? <img src={c.authorPhotoUrl} className="w-full h-full object-cover" /> : <User className="w-4 h-4 text-gray-500" />}
                </div>
                <div className="flex-1 bg-[#0B1221] border border-[#1E293B] rounded-2xl px-3 py-2">
                  <div className="flex items-center justify-between mb-1">
                    <span className="text-xs font-black text-white">{c.authorDisplayName || 'User'}</span>
                    <div className="flex items-center gap-2">
                      <span className="text-[10px] font-bold text-gray-500">{timeAgo(c.createdAtMs)}</span>
                      {c.authorId === selfUid && (
                        <button onClick={() => handleDelete(c.commentId)} className="text-gray-500 hover:text-red-500">
                          <X className="w-3 h-3" />
                        </button>
                      )}
                    </div>
                  </div>
                  <p className="text-sm font-medium text-gray-300 leading-snug whitespace-pre-wrap">{c.text}</p>
                </div>
              </div>
            ))
          )}
        </div>

        {error && <p className="px-5 text-xs font-bold text-red-500">{error}</p>}

        <div className="p-4 border-t border-[#1E293B] flex items-center gap-3 shrink-0">
          <input
            value={text}
            onChange={(e) => setText(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && handleSend()}
            disabled={sending}
            maxLength={500}
            placeholder="Add a comment…"
            className="flex-1 bg-[#1E293B]/50 border border-white/5 rounded-xl px-4 py-3 text-sm font-semibold text-white outline-none focus:border-[#BEF264]"
          />
          <button
            onClick={handleSend}
            disabled={sending || !text.trim()}
            className="w-11 h-11 flex items-center justify-center rounded-xl bg-[#BEF264] text-[#0F172A] disabled:opacity-50 hover:brightness-110 shrink-0"
          >
            {sending ? <Loader2 className="w-4 h-4 animate-spin" /> : <Send className="w-4 h-4" />}
          </button>
        </div>
      </Glass>
    </div>
  );
}
