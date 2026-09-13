'use client';

import { useEffect, useState } from 'react';
import { useParams } from 'next/navigation';
import { doc, onSnapshot } from 'firebase/firestore';
import { db, auth } from '@/lib/firebase';
import {
  PublicPost,
  PublicPostComment,
  toggleLikeWeb,
  subscribeToCommentsWeb,
  addCommentWeb,
} from '@/lib/feed/publicFeedRepository';
import { recordLinkClick } from '@/lib/services/linkAnalyticsService';
import { Glass } from '@/components/ui/Glass';
import { Loader2, Heart, MessageCircle, Trophy, User as UserIcon } from 'lucide-react';

/**
 * The public `/post/{id}` share link — the web counterpart of mobile's
 * PostDetailScreen (lib/features/social/presentation/post_detail_screen.dart).
 * Renders a single `public_posts/{postId}` document as a standalone landing
 * page so a shared post link works even for a visitor who lands directly on
 * it (rather than only ever seeing posts inline inside the feed list).
 */
export default function PostDetailPage() {
  const params = useParams();
  const postId = ((params.id as string) || '').trim();

  const [authUid, setAuthUid] = useState<string | null>(null);
  const [post, setPost] = useState<PublicPost | null>(null);
  const [loading, setLoading] = useState(true);
  const [liked, setLiked] = useState(false);
  const [liking, setLiking] = useState(false);
  const [comments, setComments] = useState<PublicPostComment[]>([]);
  const [commentText, setCommentText] = useState('');
  const [postingComment, setPostingComment] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    const unsub = auth.onAuthStateChanged((user) => setAuthUid(user?.uid || null));
    return () => unsub();
  }, []);

  useEffect(() => {
    if (!postId) return;
    recordLinkClick('post', postId);

    const unsub = onSnapshot(
      doc(db, 'public_posts', postId),
      (snap) => {
        setPost(snap.exists() ? ({ postId: snap.id, ...snap.data() } as PublicPost) : null);
        setLoading(false);
      },
      () => {
        setPost(null);
        setLoading(false);
      },
    );
    return () => unsub();
  }, [postId]);

  useEffect(() => {
    if (!postId || !authUid) return;
    const unsub = onSnapshot(
      doc(db, 'public_posts', postId, 'likes', authUid),
      (snap) => setLiked(snap.exists()),
      () => setLiked(false),
    );
    return () => {
      unsub();
      setLiked(false);
    };
  }, [postId, authUid]);

  useEffect(() => {
    if (!postId) return;
    return subscribeToCommentsWeb(postId, setComments);
  }, [postId]);

  useEffect(() => {
    document.title = post ? `${post.authorDisplayName || 'User'} on eSportlyic` : 'eSportlyic';
    return () => {
      document.title = 'eSportlyic';
    };
  }, [post]);

  async function handleLike() {
    if (!authUid) {
      setError('Please sign in to like posts.');
      return;
    }
    if (liking) return;
    setLiking(true);
    try {
      await toggleLikeWeb(postId, authUid);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLiking(false);
    }
  }

  async function handleComment() {
    if (!authUid) {
      setError('Please sign in to comment.');
      return;
    }
    const text = commentText.trim();
    if (!text || postingComment) return;

    setPostingComment(true);
    try {
      const user = auth.currentUser;
      await addCommentWeb({
        postId,
        authorId: authUid,
        authorDisplayName: user?.displayName?.trim() || 'User',
        authorPhotoUrl: user?.photoURL?.trim() || '',
        text,
      });
      setCommentText('');
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setPostingComment(false);
    }
  }

  function timeAgo(ms: number) {
    if (!ms) return '';
    return new Date(ms).toLocaleString();
  }

  if (loading) {
    return (
      <div className="flex justify-center items-center h-[50vh]">
        <Loader2 className="w-10 h-10 animate-spin text-[#BEF264]" />
      </div>
    );
  }

  if (!post || post.deleted) {
    return (
      <div className="flex flex-col items-center justify-center h-[50vh] text-gray-400 text-center px-4">
        <p className="font-bold text-white">This post is unavailable.</p>
        <p className="text-sm mt-1">It may have been removed by its author.</p>
      </div>
    );
  }

  return (
    <div className="max-w-2xl mx-auto px-4 py-6">
      <Glass className="p-4 sm:p-5 border border-[#1E293B] shadow-xl bg-[#0B1221]">
        <div className="flex items-center gap-3 mb-3">
          <div className="w-10 h-10 rounded-full bg-[#1E293B] flex items-center justify-center overflow-hidden shrink-0 border border-white/5">
            {post.authorPhotoUrl ? (
              <img src={post.authorPhotoUrl} alt="Author" className="w-full h-full object-cover" />
            ) : (
              <UserIcon className="w-5 h-5 text-gray-500" />
            )}
          </div>
          <div>
            <h4 className="font-bold text-white text-sm leading-tight">{post.authorDisplayName || 'User'}</h4>
            {post.createdAtMs > 0 && (
              <p className="text-xs text-gray-500 font-semibold">{timeAgo(post.createdAtMs)}</p>
            )}
          </div>
        </div>

        {post.leagueName && (
          <div className="mb-3 inline-flex items-center gap-2 px-3 py-1.5 rounded-full bg-[#BEF264]/10 border border-[#BEF264]/25">
            <Trophy className="w-3.5 h-3.5 text-[#BEF264]" />
            <span className="text-xs font-black text-[#BEF264]">{post.leagueName}</span>
          </div>
        )}

        {post.text && (
          <p className="text-sm text-gray-300 mb-3 whitespace-pre-wrap leading-relaxed">{post.text}</p>
        )}

        {post.mediaUrl && (
          <div className="mb-4 rounded-2xl overflow-hidden bg-black">
            <img src={post.mediaUrl} alt="Post media" className="w-full object-cover max-h-[450px]" />
          </div>
        )}

        <div className="flex items-center gap-6 pt-2">
          <button
            onClick={handleLike}
            disabled={liking}
            className={`flex items-center gap-2 transition-colors group ${liked ? 'text-red-500' : 'text-gray-400 hover:text-red-500'}`}
          >
            <Heart className="w-5 h-5 group-active:scale-90 transition-transform" fill={liked ? 'currentColor' : 'none'} />
            <span className="text-xs font-bold">{post.likeCount}</span>
          </button>
          <div className="flex items-center gap-2 text-gray-400">
            <MessageCircle className="w-5 h-5" />
            <span className="text-xs font-bold">{post.commentCount}</span>
          </div>
        </div>
      </Glass>

      {error && (
        <p className="text-xs text-red-400 font-semibold mt-3 px-1">{error}</p>
      )}

      <div className="mt-6">
        <h5 className="text-sm font-black text-white mb-3">Comments</h5>
        <div className="flex items-center gap-2 mb-4">
          <input
            value={commentText}
            onChange={(e) => setCommentText(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && handleComment()}
            placeholder="Write a comment…"
            className="flex-1 bg-[#0B1221] border border-[#1E293B] rounded-xl px-3 py-2 text-sm text-white placeholder:text-gray-500 outline-none focus:border-[#BEF264]/40"
          />
          <button
            onClick={handleComment}
            disabled={postingComment}
            className="px-4 py-2 rounded-xl bg-[#BEF264] text-[#0F172A] text-sm font-black disabled:opacity-50"
          >
            {postingComment ? '…' : 'Send'}
          </button>
        </div>

        {comments.length === 0 ? (
          <p className="text-sm text-gray-500 font-semibold">No comments yet.</p>
        ) : (
          <div className="space-y-2">
            {comments.map((c) => (
              <Glass key={c.commentId} className="p-3 border border-[#1E293B] bg-[#0B1221]">
                <p className="text-xs font-black text-white mb-1">{c.authorDisplayName || 'User'}</p>
                <p className="text-sm text-gray-300 font-medium leading-snug">{c.text}</p>
              </Glass>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
