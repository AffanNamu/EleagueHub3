'use client';

import { useState } from 'react';
import Image from 'next/image';
import { UploadCloud, Loader2 } from 'lucide-react';
import { useMarketplaceProductSave } from '@/hooks/useMarketplaceActions';
import { uploadMarketplaceProductImage } from '@/lib/cloudinary/adminCloudinaryUpload';
import type { MarketplaceProduct, MarketplaceProductInput } from '@/types/marketplaceProduct';

const inputClass =
  'w-full rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-primary outline-none focus:border-brand';
const labelClass = 'mb-1.5 block text-sm text-ink-secondary';

export function MarketplaceProductForm({ existing }: { existing?: MarketplaceProduct }) {
  const { save, submitting, error } = useMarketplaceProductSave(existing?.id);

  const [name, setName] = useState(existing?.name ?? '');
  const [price, setPrice] = useState(existing?.price ?? '');
  const [description, setDescription] = useState(existing?.description ?? '');
  const [imageUrl, setImageUrl] = useState(existing?.imageUrl ?? '');
  const [affiliateUrl, setAffiliateUrl] = useState(existing?.affiliateUrl ?? '');
  const [category, setCategory] = useState(existing?.category ?? '');
  const [sellerName, setSellerName] = useState(existing?.sellerName ?? '');

  const [uploading, setUploading] = useState(false);
  const [uploadError, setUploadError] = useState<string | null>(null);

  async function handleFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;

    setUploading(true);
    setUploadError(null);
    try {
      const url = await uploadMarketplaceProductImage(file);
      setImageUrl(url);
    } catch (err) {
      setUploadError(err instanceof Error ? err.message : 'Upload failed.');
    } finally {
      setUploading(false);
      e.target.value = '';
    }
  }

  async function handleSubmit() {
    const input: MarketplaceProductInput = {
      name,
      price,
      description,
      imageUrl,
      affiliateUrl,
      category,
      sellerName,
    };
    await save(input);
  }

  const canSubmit =
    !submitting &&
    name.trim().length > 0 &&
    price.trim().length > 0 &&
    affiliateUrl.trim().length > 0 &&
    category.trim().length > 0 &&
    sellerName.trim().length > 0;

  return (
    <div className="panel space-y-4 p-5">
      {error && (
        <div className="rounded-sm border border-signal-danger/40 bg-signal-dangerFaint px-3 py-2 text-sm text-signal-danger">
          {error}
        </div>
      )}

      <div>
        <label className={labelClass}>Product name</label>
        <input value={name} onChange={(e) => setName(e.target.value)} maxLength={120} className={inputClass} />
      </div>

      <div className="grid grid-cols-2 gap-3">
        <div>
          <label className={labelClass}>Price</label>
          <input
            value={price}
            onChange={(e) => setPrice(e.target.value)}
            placeholder="e.g. $49.99"
            className={inputClass}
          />
        </div>
        <div>
          <label className={labelClass}>Category</label>
          <input
            value={category}
            onChange={(e) => setCategory(e.target.value)}
            placeholder="e.g. Jerseys, Equipment"
            className={inputClass}
          />
        </div>
      </div>

      <div>
        <label className={labelClass}>Seller name</label>
        <input value={sellerName} onChange={(e) => setSellerName(e.target.value)} className={inputClass} />
      </div>

      <div>
        <label className={labelClass}>Description</label>
        <textarea
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          maxLength={2000}
          rows={4}
          className={inputClass}
        />
      </div>

      <div>
        <label className={labelClass}>Affiliate URL</label>
        <input
          value={affiliateUrl}
          onChange={(e) => setAffiliateUrl(e.target.value)}
          placeholder="https://…"
          className={inputClass}
        />
        <p className="mt-1 text-xs text-ink-muted">Where "Buy" sends the user — an off-platform store/affiliate link.</p>
      </div>

      <div>
        <label className={labelClass}>Image</label>
        <div className="flex items-center gap-3">
          {imageUrl ? (
            <Image
              src={imageUrl}
              alt={name || 'Product image'}
              width={64}
              height={64}
              className="rounded-sm border border-base-border object-cover"
            />
          ) : (
            <div className="flex h-16 w-16 items-center justify-center rounded-sm border border-dashed border-base-border text-ink-muted">
              <UploadCloud size={20} />
            </div>
          )}
          <label className="flex cursor-pointer items-center gap-2 rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-secondary hover:text-ink-primary">
            {uploading ? <Loader2 size={14} className="animate-spin" /> : <UploadCloud size={14} />}
            {uploading ? 'Uploading…' : 'Upload image'}
            <input type="file" accept="image/*" className="hidden" onChange={handleFileChange} disabled={uploading} />
          </label>
        </div>
        {uploadError && <p className="mt-1.5 text-xs text-signal-danger">{uploadError}</p>}
      </div>

      <div className="flex justify-end pt-2">
        <button
          onClick={handleSubmit}
          disabled={!canSubmit}
          className="rounded-sm bg-brand px-4 py-2 text-sm font-medium text-base hover:bg-brand-soft disabled:opacity-60"
        >
          {submitting ? 'Saving…' : existing ? 'Save changes' : 'Create listing'}
        </button>
      </div>
    </div>
  );
}
