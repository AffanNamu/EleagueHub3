'use client';

import { useState, useEffect, useRef } from 'react';
import { useRouter } from 'next/navigation';
import { collection, query, orderBy, limit, onSnapshot } from 'firebase/firestore';
import { auth, db } from '@/lib/firebase';
import { PublicPost, toggleLikeWeb, deletePostWeb, createPostWeb } from '@/lib/feed/publicFeedRepository';
import { PostCard } from '@/components/feed/PostCard';
import { CommentsModal } from '@/components/feed/CommentsModal';
import { uploadImageFile } from '@/lib/cloudinary/cloudinaryUpload';
import { Loader2, Plus, X, Image as ImageIcon, Music2 } from 'lucide-react';
import { Glass } from '@/components/ui/Glass';

export default function PublicFeedScreen() {
  const router = useRouter();
  const [posts, setPosts] = useState<PublicPost[]>([]);
  const [loading, setLoading] = useState(true);
  const [authUid, setAuthUid] = useState<string | null>(null);

  // Create Modal State
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [postText, setPostText] = useState('');
  const [imageFile, setImageFile] = useState<File | null>(null);
  const [audioFile, setAudioFile] = useState<File | null>(null);
  const [uploading, setUploading] = useState(false);

  // NEW: which post's comments sheet is open, if any. Previously there
  // was no comments UI on web at all.
  const [activeCommentsPostId, setActiveCommentsPostId] = useState<string | null>(null);

  const imageRef = useRef<HTMLInputElement>(null);
  const audioRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const unsub = auth.onAuthStateChanged(user => setAuthUid(user?.uid || null));
    return () => unsub();
  }, []);

  useEffect(() => {
    const q = query(collection(db, 'public_posts'), orderBy('createdAtMs', 'desc'), limit(50));
    const unsubscribe = onSnapshot(q, (snap) => {
      const data = snap.docs.map(doc => ({ postId: doc.id, ...doc.data() } as PublicPost));
      // Strict Parity: Client-side filtering bypasses complex index requirements
      setPosts(data.filter(p => !p.deleted));
      setLoading(false);
    });
    return () => unsubscribe();
  }, []);

  const handleCreateSubmit = async () => {
    if (!authUid) return;
    if (!postText.trim() && !imageFile && !audioFile) return alert("Add text, an image, or sound.");
    
    setUploading(true);
    try {
      let mediaUrl = '';
      let audioUrl = '';

      if (imageFile) {
        const imgRes = await uploadImageFile({ file: imageFile, folder: 'eleaguehub/public_posts' });
        mediaUrl = imgRes.secureUrl;
      }

      // Cloudinary handles audio files under the resource_type: "video" natively
      if (audioFile) {
        const audRes = await uploadImageFile({ file: audioFile, folder: 'eleaguehub/public_posts', resourceType: 'video' });
        audioUrl = audRes.secureUrl;
      }

      await createPostWeb({
        authorId: authUid,
        authorDisplayName: auth.currentUser?.displayName || 'User',
        authorPhotoUrl: auth.currentUser?.photoURL || '',
        text: postText,
        mediaUrl,
        audioUrl
      });

      setIsModalOpen(false);
      setPostText('');
      setImageFile(null);
      setAudioFile(null);
    } catch (err: any) {
      alert("Upload failed: " + err.message);
    } finally {
      setUploading(false);
    }
  };

  return (
    <div className="max-w-2xl mx-auto pb-24 px-4 sm:px-0">
      
      {/* ── TABS ── */}
      <div className="flex gap-2 mb-6 sticky top-16 z-30 bg-[#070B14]/90 backdrop-blur-md py-4">
        <button className="flex-1 py-3 bg-[#BEF264] text-[#0F172A] font-black rounded-xl text-sm shadow-lg shadow-[#BEF264]/20">For You</button>
        <button className="flex-1 py-3 bg-[#0B1221] text-gray-400 font-black rounded-xl text-sm border border-[#1E293B]">Latest</button>
      </div>

      {loading ? (
        <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 text-[#BEF264] animate-spin" /></div>
      ) : posts.length === 0 ? (
        <div className="text-center py-20 bg-[#0B1221] border border-[#1E293B] rounded-3xl">
          <p className="text-gray-400 font-bold">No posts yet. Be the first to share something!</p>
        </div>
      ) : (
        <div className="space-y-6">
          {posts.map(post => (
            <PostCard 
              key={post.postId} 
              post={post} 
              isOwner={post.authorId === authUid} 
              onLike={() => authUid && toggleLikeWeb(post.postId, authUid)}
              onDelete={() => authUid && deletePostWeb(post.postId, authUid)}
              onOpenLeague={() => router.push(`/leagues/${post.leagueId}`)}
              onComment={() => setActiveCommentsPostId(post.postId)}
            />
          ))}
        </div>
      )}

      {/* ── CREATE FAB ── */}
      {authUid && (
        <button 
          onClick={() => setIsModalOpen(true)}
          className="fixed bottom-20 right-6 md:right-10 w-14 h-14 bg-[#BEF264] text-[#0F172A] rounded-full shadow-2xl flex items-center justify-center hover:scale-110 transition-transform z-40"
        >
          <Plus className="w-6 h-6" />
        </button>
      )}

      {/* ── CREATE MODAL ── */}
      {isModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-sm">
          <Glass className="w-full max-w-lg bg-[#0F172A] border border-[#1E293B] rounded-3xl p-6 shadow-2xl">
            <div className="flex justify-between items-center mb-4">
              <h2 className="text-xl font-black text-white">Create Post</h2>
              <button onClick={() => !uploading && setIsModalOpen(false)} className="text-gray-500 hover:text-white"><X className="w-5 h-5"/></button>
            </div>

            <textarea 
              value={postText} onChange={e => setPostText(e.target.value)}
              placeholder="What's happening in your competitive scene?"
              className="w-full h-32 bg-[#0B1221] border border-[#1E293B] rounded-xl p-4 text-white resize-none outline-none focus:border-[#BEF264] mb-4"
              disabled={uploading}
            />

            <div className="flex flex-col gap-3 mb-6">
              {/* Media Previews */}
              {imageFile && <div className="p-3 bg-[#1E293B] rounded-xl text-xs font-bold text-white flex justify-between">Image attached: {imageFile.name} <button onClick={() => setImageFile(null)}><X className="w-4 h-4 text-red-500"/></button></div>}
              {audioFile && <div className="p-3 bg-amber-500/10 border border-amber-500/30 rounded-xl text-xs font-bold text-amber-500 flex justify-between">Audio attached: {audioFile.name} <button onClick={() => setAudioFile(null)}><X className="w-4 h-4 text-red-500"/></button></div>}

              {/* Upload Buttons */}
              <div className="flex gap-2">
                <input type="file" accept="image/*" ref={imageRef} onChange={e => setImageFile(e.target.files?.[0] || null)} className="hidden" />
                <input type="file" accept="audio/*" ref={audioRef} onChange={e => setAudioFile(e.target.files?.[0] || null)} className="hidden" />
                
                <button onClick={() => imageRef.current?.click()} disabled={uploading} className="flex-1 py-3 bg-[#1E293B] hover:bg-[#2A3A52] rounded-xl text-xs font-bold text-white flex items-center justify-center gap-2"><ImageIcon className="w-4 h-4"/> Image</button>
                <button onClick={() => audioRef.current?.click()} disabled={uploading} className="flex-1 py-3 bg-[#1E293B] hover:bg-[#2A3A52] rounded-xl text-xs font-bold text-white flex items-center justify-center gap-2"><Music2 className="w-4 h-4"/> Sound</button>
              </div>
            </div>

            <button 
              onClick={handleCreateSubmit} disabled={uploading}
              className="w-full py-4 bg-[#BEF264] text-[#0F172A] font-black rounded-xl hover:brightness-110 disabled:opacity-50 flex justify-center shadow-lg shadow-[#BEF264]/10"
            >
              {uploading ? <Loader2 className="w-5 h-5 animate-spin" /> : 'Post to Feed'}
            </button>
          </Glass>
        </div>
      )}

      {/* ── COMMENTS MODAL ── */}
      {activeCommentsPostId && (
        <CommentsModal
          postId={activeCommentsPostId}
          onClose={() => setActiveCommentsPostId(null)}
        />
      )}
    </div>
  );
}
