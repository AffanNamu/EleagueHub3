'use client';

import { useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { auth } from '@/lib/firebase';
import { onAuthStateChanged } from 'firebase/auth';
import { uploadImageFile } from '@/lib/cloudinary/cloudinaryUpload';
import { createMarketplaceProductWeb } from '@/lib/marketplace/marketplaceRepository';
import { Glass } from '@/components/ui/Glass';
import { ArrowLeft, Loader2, ImagePlus, ShieldAlert, UploadCloud } from 'lucide-react';

// Mirrors admin_marketplace_upload_screen.dart's _superAdminUid — the
// same super admin uid firestore.rules' marketplace_products create rule
// requires as request.auth.uid, matching request.resource.data.createdBy.
const SUPER_ADMIN_UID = 'a0JDUelQW3TEyoXTm4ESuGi7ndq1';

// Mirrors marketplace_screen.dart's category list (minus "All", which
// only makes sense as a browse filter, not a product's own category).
const CATEGORIES = ['Gamepads', 'Jerseys', 'Boots', 'Accessories'];

const MAX_IMAGE_BYTES = 8 * 1024 * 1024;

function looksLikeHttpUrl(s: string): boolean {
  const u = s.trim().toLowerCase();
  return u.startsWith('https://') || u.startsWith('http://');
}

export default function AdminMarketplaceUploadScreen() {
  const router = useRouter();
  const [authUid, setAuthUid] = useState<string | null>(null);
  const [authLoading, setAuthLoading] = useState(true);

  const [name, setName] = useState('');
  const [price, setPrice] = useState('');
  const [sellerName, setSellerName] = useState('');
  const [category, setCategory] = useState(CATEGORIES[0]);
  const [affiliateUrl, setAffiliateUrl] = useState('');
  const [description, setDescription] = useState('');

  const [imageFile, setImageFile] = useState<File | null>(null);
  const [imagePreview, setImagePreview] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    const unsub = onAuthStateChanged(auth, (u) => {
      setAuthUid(u?.uid ?? null);
      setAuthLoading(false);
    });
    return () => unsub();
  }, []);

  function handlePickImage(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;

    if (file.size > MAX_IMAGE_BYTES) {
      setError('Image too large. Max 8MB.');
      return;
    }

    setError('');
    setImageFile(file);
    setImagePreview(URL.createObjectURL(file));
  }

  function resetForm() {
    setName('');
    setPrice('');
    setSellerName('');
    setCategory(CATEGORIES[0]);
    setAffiliateUrl('');
    setDescription('');
    setImageFile(null);
    setImagePreview(null);
  }

  async function handleUpload() {
    if (uploading || !authUid) return;
    if (authUid !== SUPER_ADMIN_UID) {
      setError('Access denied.');
      return;
    }

    if (!name.trim()) return setError('Product name is required');
    if (!price.trim()) return setError('Price is required');
    if (!sellerName.trim()) return setError('Seller name is required');
    if (!description.trim()) return setError('Description is required');
    if (!looksLikeHttpUrl(affiliateUrl)) return setError('Affiliate link must start with http/https.');
    if (!imageFile) return setError('Please select an image.');

    setUploading(true);
    setError('');
    try {
      const { secureUrl } = await uploadImageFile({ file: imageFile, folder: 'eleaguehub/marketplace_products' });

      await createMarketplaceProductWeb({
        name: name.trim(),
        price: price.trim(),
        description: description.trim(),
        imageUrl: secureUrl,
        affiliateUrl: affiliateUrl.trim(),
        category,
        sellerName: sellerName.trim(),
        createdBy: authUid,
      });

      alert('Uploaded successfully.');
      resetForm();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Upload failed.');
    } finally {
      setUploading(false);
    }
  }

  if (authLoading) {
    return <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 text-brand-lime animate-spin" /></div>;
  }

  const isAllowed = authUid === SUPER_ADMIN_UID;

  return (
    <div className="max-w-xl mx-auto space-y-4 pb-20">
      <div className="flex items-center gap-4">
        <button onClick={() => router.back()} className="p-2.5 bg-brand-surface hover:bg-white/10 rounded-xl transition-colors">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <div>
          <h1 className="text-xl font-black text-white flex items-center gap-2"><UploadCloud className="w-5 h-5 text-brand-lime" /> Upload Product</h1>
          <p className="text-xs text-gray-400 font-semibold">Admin only</p>
        </div>
      </div>

      {!isAllowed ? (
        <Glass className="p-10 text-center flex flex-col items-center">
          <ShieldAlert className="w-10 h-10 text-brand-red mb-3" />
          <p className="text-lg font-black text-white">Access Denied</p>
        </Glass>
      ) : (
        <>
          <Glass className="p-4 space-y-3">
            <p className="text-sm font-black text-gray-300">Product Image</p>
            <div className="aspect-[16/9] rounded-2xl bg-white/[0.03] border border-white/10 overflow-hidden flex items-center justify-center">
              {imagePreview ? (
                <img src={imagePreview} alt="Preview" className="w-full h-full object-cover" />
              ) : (
                <p className="text-xs font-semibold text-gray-500">No image selected</p>
              )}
            </div>
            <input ref={fileInputRef} type="file" accept="image/*" className="hidden" onChange={handlePickImage} />
            <button
              onClick={() => fileInputRef.current?.click()}
              disabled={uploading}
              className="w-full py-3 rounded-xl bg-brand-lime text-brand-navy font-black flex items-center justify-center gap-2 disabled:opacity-50"
            >
              <ImagePlus className="w-4 h-4" /> Select Image
            </button>
          </Glass>

          <Glass className="p-4 space-y-3">
            <input value={name} onChange={(e) => setName(e.target.value)} disabled={uploading} placeholder="Product Name" className="w-full bg-brand-surface border border-white/10 rounded-xl p-3 text-white outline-none focus:border-brand-lime" />
            <input value={price} onChange={(e) => setPrice(e.target.value)} disabled={uploading} placeholder="Price (e.g. $49.99)" className="w-full bg-brand-surface border border-white/10 rounded-xl p-3 text-white outline-none focus:border-brand-lime" />
            <input value={sellerName} onChange={(e) => setSellerName(e.target.value)} disabled={uploading} placeholder="Seller Name" className="w-full bg-brand-surface border border-white/10 rounded-xl p-3 text-white outline-none focus:border-brand-lime" />
            <select value={category} onChange={(e) => setCategory(e.target.value)} disabled={uploading} className="w-full bg-brand-surface border border-white/10 rounded-xl p-3 text-white outline-none focus:border-brand-lime">
              {CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}
            </select>
            <input value={affiliateUrl} onChange={(e) => setAffiliateUrl(e.target.value)} disabled={uploading} placeholder="Affiliate Link (https://...)" className="w-full bg-brand-surface border border-white/10 rounded-xl p-3 text-white outline-none focus:border-brand-lime" />
            <textarea value={description} onChange={(e) => setDescription(e.target.value)} disabled={uploading} placeholder="Description" rows={4} className="w-full bg-brand-surface border border-white/10 rounded-xl p-3 text-white outline-none focus:border-brand-lime resize-none" />

            {error && <p className="text-xs font-bold text-brand-red">{error}</p>}

            <button
              onClick={handleUpload}
              disabled={uploading}
              className="w-full py-4 rounded-xl bg-brand-lime text-brand-navy font-black disabled:opacity-50 flex items-center justify-center"
            >
              {uploading ? <Loader2 className="w-5 h-5 animate-spin" /> : 'Upload Product'}
            </button>
          </Glass>
        </>
      )}
    </div>
  );
}
