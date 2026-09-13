'use client';

import { useRef, useState } from 'react';
import { uploadImageFile } from '@/lib/cloudinary/cloudinaryUpload';
import { createStatusWeb } from '@/lib/status/statusRepository';
import { Glass } from '@/components/ui/Glass';
import { ImagePlus, Loader2, X } from 'lucide-react';

/**
 * Web port of showCreateStatusSheet (create_status_sheet.dart). Posts a
 * 24h image status for the signed-in user — folder/preset match the
 * Dart version's Cloudinary upload (eleaguehub/statuses) so status images
 * from both platforms live in the same account.
 */
export function CreateStatusModal({ onClose, onPosted }: { onClose: () => void; onPosted: () => void }) {
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [file, setFile] = useState<File | null>(null);
  const [previewUrl, setPreviewUrl] = useState('');
  const [caption, setCaption] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  function handlePick(e: React.ChangeEvent<HTMLInputElement>) {
    const picked = e.target.files?.[0];
    if (!picked) return;
    setFile(picked);
    setPreviewUrl(URL.createObjectURL(picked));
    setError('');
  }

  async function submit() {
    if (!file) {
      setError('Please select an image first.');
      return;
    }
    setBusy(true);
    setError('');
    try {
      const { secureUrl } = await uploadImageFile({ file, folder: 'eleaguehub/statuses', publicIdPrefix: 'status' });
      await createStatusWeb({ imageUrl: secureUrl, caption });
      onPosted();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Something went wrong. Please try again.');
      setBusy(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/70 p-0 sm:p-4" onClick={onClose}>
      <Glass
        className="w-full sm:max-w-md p-5 border border-[#1E293B] bg-[#0B1221] rounded-b-none sm:rounded-3xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between mb-1">
          <h3 className="text-base font-black text-white">Add Status</h3>
          <button onClick={onClose} className="text-gray-500 hover:text-white">
            <X className="w-5 h-5" />
          </button>
        </div>
        <p className="text-xs text-gray-500 font-semibold mb-4">Visible to everyone for 24 hours.</p>

        <button
          onClick={() => !busy && fileInputRef.current?.click()}
          className="w-full h-36 rounded-2xl border border-[#1E293B] bg-[#070B14] flex items-center justify-center overflow-hidden mb-3"
        >
          {previewUrl ? (
            <img src={previewUrl} alt="Status preview" className="w-full h-full object-cover" />
          ) : (
            <div className="flex flex-col items-center gap-2 text-gray-500">
              <ImagePlus className="w-7 h-7" />
              <span className="text-xs font-bold">Tap to select image</span>
            </div>
          )}
        </button>
        <input ref={fileInputRef} type="file" accept="image/*" onChange={handlePick} className="hidden" />

        <textarea
          value={caption}
          onChange={(e) => setCaption(e.target.value.slice(0, 200))}
          placeholder="Add a caption (optional)"
          maxLength={200}
          rows={2}
          disabled={busy}
          className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl px-3 py-2 text-sm text-white placeholder:text-gray-500 outline-none focus:border-[#BEF264]/40 resize-none mb-2"
        />

        {error && <p className="text-xs text-red-400 font-semibold mb-2">{error}</p>}

        <button
          onClick={submit}
          disabled={busy}
          className="w-full py-3 rounded-xl bg-[#BEF264] text-[#0F172A] text-sm font-black disabled:opacity-50 flex items-center justify-center gap-2"
        >
          {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : null}
          {busy ? 'Posting…' : 'Post Status'}
        </button>
      </Glass>
    </div>
  );
}
